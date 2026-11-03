"""Matched refinement against the current robust-jump frontier; isolated R4."""
import argparse,hashlib,json,multiprocessing as mp,os,time
from pathlib import Path
import gpt_competitor as base
from gpt_jump_recover import legal
from search import BoxRep,Problem,Search,describe,read_params,jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_jump_round4';PARAMS=ROOT/'params/competitor_jump_round4'
TRAIN=list(range(277101,277117));VALID=list(range(278101,278165));SECONDS=8.;BUDGET=3072
BACKBONE=['crouch_t','extend_t','to_z','drv_hip','drv_arm','stand_after','stand_t','stand_gain','stand_hip_flex','stand_knee','stand_ankle','stand_spine_flex','stand_shoulder_flex','d_land','k_la','k_lh']
def controller(v):return str(ROOT/f'bin/challengers/gpt-jump-general-{v}')
def initial(v):return read_params(ROOT/f'params/competitor_jump_round3/{v}.txt')
def run(job):
    v,p,seed,seconds,kind,trace=job;base.OUT=OUT;base.ctl_path=lambda task,mode:controller(mode)
    _,m,wall=base.run(('jump',v,p,seed,seconds,{'trace':trace} if trace else {}))
    if 'error' in m:return -1e9,m,wall
    early=m['three_second'];ok3=legal(early);ok8=legal(m)
    penalty=.01*max(m['peak_grf_bw']-4.,0.)**2+.0002*max(m['peak_loading_bw_s']-100.,0.)
    score=100.*ok8+20.*ok3+2.*max(early.get('mark',0.),0.)+.5*max(m.get('mark',0.),0.)*ok8-penalty
    return score,m,wall
class GeneralProblem(Problem):
    def __init__(self,v,rep):super().__init__('search_jump_v3',rep,TRAIN,SECONDS,risk=.5);self.v=v
    def jobs(self,x,seeds=None):return [(self.v,self.rep.decode(x),s,SECONDS,'candidate',None) for s in (seeds or self.seeds)]
def stats(ms):
    good3=[m['three_second'] for m in ms if legal(m['three_second'])];good8=[m for m in ms if legal(m)]
    return {'n':len(ms),'legal3':len(good3),'mean3':sum(m['mark'] for m in good3)/len(good3) if good3 else None,'legal8':len(good8),'mean8':sum(m['mark'] for m in good8)/len(good8) if good8 else None,'mean_peak_bw':sum(m['peak_grf_bw'] for m in ms)/len(ms)}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['train','validate']);ap.add_argument('variant',choices=['pure','tcn']);a=ap.parse_args();p=initial(a.variant);os.environ['ROBOLAB_CONTROLLER']=controller(a.variant)
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='train':
            tun=describe('search_jump_v3',p);rep=BoxRep.from_tunables(tun,only=BACKBONE,init=p);assert rep.n==16,rep.names
            search=Search(GeneralProblem(a.variant,rep),'oneplusone',BUDGET,280928,.012,out=str(PARAMS/f'{a.variant}.txt'),log=str(OUT/f'{a.variant}.jsonl'),archive=str(OUT/f'{a.variant}.npz'),label='gpt: general recovery '+a.variant)
            print('BEGIN',a.variant,'dimensions',rep.n,'budget',BUDGET,flush=True)
            while not search.done:
                jobs=search.next_jobs()
                if not jobs:break
                results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results)
                search.consume(results)
                if search.gen%10==0 or search.done or search.gen==1:print(a.variant,'used',search.used,'best',search.best[0],'wall',round(time.time()-search.t0,1),flush=True)
            summary=search.summary();(OUT/f'{a.variant}.json').write_text(json.dumps(jsonable(summary),indent=2)+'\n')
            assert all(summary['params'].get(f'gpt_w{i}',0)==p.get(f'gpt_w{i}',0) for i in range(20))
            print('FINAL',a.variant,stats(summary['metrics']),flush=True)
        else:
            candidate=read_params(PARAMS/f'{a.variant}.txt');jobs=[]
            for s in VALID:
                for kind in (['previous','candidate','bias_only','zero_head'] if a.variant=='tcn' else ['previous','candidate']):
                    prm=dict(candidate)
                    if kind=='previous':prm=dict(p)
                    if kind=='bias_only':prm.update({f'gpt_w{i}':0. for i in range(20) if i%5})
                    if kind=='zero_head':prm.update({f'gpt_w{i}':0. for i in range(20)})
                    jobs.append((a.variant,prm,s,8.,kind,f'{a.variant}_{kind}_validation.npz' if s==VALID[0] else None))
            results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results)
            rows=[{'seed':j[2],'kind':j[4],'score':r[0],'metrics':r[1],'wall':r[2]} for j,r in zip(jobs,results)]
            (OUT/f'{a.variant}_validate.json').write_text(json.dumps(jsonable(rows),indent=2)+'\n')
            for kind in sorted({r['kind'] for r in rows}):print(a.variant,kind,stats([r['metrics'] for r in rows if r['kind']==kind]),flush=True)
if __name__=='__main__':main()
