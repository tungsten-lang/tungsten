"""Equal-budget jump recovery/distance refinement on disjoint new starts."""
import argparse,hashlib,json,multiprocessing as mp,os,time
from pathlib import Path
import gpt_competitor as base
from search import BoxRep,Problem,Search,describe,read_params,jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_jump_round2';PARAMS=ROOT/'params/competitor_jump_round2'
TRAIN=list(range(273101,273109));VALID=list(range(274101,274133));SECONDS=8.
BACKBONE=['crouch_t','extend_t','to_z','drv_hip','drv_arm','stand_after','stand_t','stand_gain','stand_hip_flex','stand_ankle','d_land','k_la']
def legal(m):return bool(m.get('takeoff')) and not any(m.get(k) for k in ['fallen','foul','inverted'])
def controller(variant):return str(ROOT/f'bin/challengers/gpt-jump-recover-{variant}')
def initial(variant):
    p=json.loads((OUT/'probe_params.json').read_text())['rise'];p['gpt_temporal']=float(variant=='tcn')
    p.update({f'gpt_w{i}':0. for i in range(20)})
    return p

def run(job):
    variant,p,seed,seconds,kind,trace=job
    base.OUT=OUT;base.ctl_path=lambda problem,mode:controller(mode)
    old,m,wall=base.run(('jump',variant,p,seed,seconds,{'trace':trace} if trace else {}))
    if 'error' in m:return -1e9,m,wall
    early=m['three_second'];ok3=legal(early);ok8=legal(m)
    penalty=.01*max(m['peak_grf_bw']-4.,0.)**2+.0002*max(m['peak_loading_bw_s']-100.,0.)
    score=3.*ok3+3.*ok8+2.*max(early.get('mark',0.),0.)+max(m.get('mark',0.),0.)*ok8+.5*m['fall_time']/seconds-penalty
    if early.get('foul') or m.get('foul'):score-=3.
    return score,m,wall

class RecoverProblem(Problem):
    def __init__(self,variant,rep):
        super().__init__('search_jump_v3',rep,TRAIN,SECONDS,risk=.5);self.variant=variant
    def jobs(self,x,seeds=None):return [(self.variant,self.rep.decode(x),seed,SECONDS,'candidate',None) for seed in (seeds or self.seeds)]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['train','validate']);ap.add_argument('variant',choices=['pure','tcn']);ap.add_argument('--budget',type=int,default=2048);a=ap.parse_args()
    p=initial(a.variant);os.environ['ROBOLAB_CONTROLLER']=controller(a.variant)
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='train':
            tun=describe('search_jump_v3',p);rep=BoxRep.from_tunables(tun,only=['gpt_w*']+BACKBONE,init=p)
            assert rep.n==32,rep.names
            s=Search(RecoverProblem(a.variant,rep),'oneplusone',a.budget,270929,.015,out=str(PARAMS/f'{a.variant}.txt'),log=str(OUT/f'{a.variant}.jsonl'),archive=str(OUT/f'{a.variant}.npz'),label='gpt: jump recover '+a.variant)
            print(a.variant,'dimensions',rep.n,'rollouts',a.budget,flush=True)
            while not s.done:
                jobs=s.next_jobs()
                if not jobs:break
                s.consume(pool.map(run,jobs,chunksize=1))
                if s.gen%20==0 or s.done or s.gen==1:print(a.variant,s.used,s.best[0],round(time.time()-s.t0,1),flush=True)
            (OUT/f'{a.variant}.json').write_text(json.dumps(jsonable(s.summary()),indent=2)+'\n')
        else:
            p.update(read_params(PARAMS/f'{a.variant}.txt'));jobs=[]
            for seed in VALID:
                for kind in (['start','candidate','bias_only','zero_head'] if a.variant=='tcn' else ['start','candidate']):
                    prm=dict(p)
                    if kind=='start':prm=initial(a.variant)
                    if kind=='bias_only':prm.update({f'gpt_w{i}':0. for i in range(20) if i%5})
                    if kind=='zero_head':prm.update({f'gpt_w{i}':0. for i in range(20)})
                    trace=f'{a.variant}_{kind}_validation.npz' if seed==VALID[0] else None
                    jobs.append((a.variant,prm,seed,SECONDS,kind,trace))
            results=pool.map(run,jobs,chunksize=1);rows=[{'seed':j[2],'kind':j[4],'score':r[0],'metrics':r[1],'wall':r[2]} for j,r in zip(jobs,results)]
            (OUT/f'{a.variant}_validate.json').write_text(json.dumps(jsonable(rows),indent=2)+'\n')
            for kind in sorted({r['kind'] for r in rows}):
                ms=[r['metrics'] for r in rows if r['kind']==kind];ok=[m for m in ms if legal(m)];early=[m['three_second'] for m in ms if legal(m['three_second'])]
                print(a.variant,kind,{'legal8':len(ok),'mean8':sum(m['mark'] for m in ok)/max(len(ok),1),'legal3':len(early),'mean3':sum(m['mark'] for m in early)/max(len(early),1),'mean_peak_bw':sum(m['peak_grf_bw'] for m in ms)/len(ms)},flush=True)
if __name__=='__main__':main()
