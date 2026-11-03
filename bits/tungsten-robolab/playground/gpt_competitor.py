"""Private, reproducible six-challenger experiment. Never edits shared tasks.

Train: python playground/gpt_competitor.py train jump pure --budget 1024
Validate: ... validate jump pure
All optimization uses fresh training starts, disjoint from arena and validation.
The causal TCN learns a zero-initialized readout over fixed conv features; the
pure-search control learns offsets indexed only by the explicit motion phase.
"""
import argparse, hashlib, importlib, json, multiprocessing as mp, os, time
from pathlib import Path
for key in ('OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','VECLIB_MAXIMUM_THREADS'):
    os.environ[key]='1'
os.environ['BAT_BODY']='athlete'
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
OUT=ROOT/'out/competitor_20260927'
PARAMS=ROOT/'params/competitor_20260927'
import numpy as np
import mujoco
from bridge import Sim
from search import BoxRep, Problem, Search, describe, read_params, jsonable
CONFIG={
 'jump':('search_jump_v3','search_jump_legal',6.0,['to_z','td_z','land_t','g_land','d_land','k_lp','k_la','kd_lp']),
 'bat':('bat','bat_power',7.8,['t_trigger','lag_torso','lag_arms','dur_mid','dur_whip','dur_drive','arm_swing_kp','wrist_rel_kp']),
 'dribble':('dribble','dribble_crossover_25',15.0,['x_t','x_kv','x_steer','x_lead','c_kv','c_tmax','t_rec','pump']),
}
TRAIN=list(range(270901,270909))
VALID=list(range(271001,271025))
def ctl_path(problem,variant):return str(ROOT/(f'bin/challengers/gpt-{problem}-{variant}'+('-v2' if problem=='dribble' else '')))
def initial(problem,variant):
    champ=json.loads((OUT/'champions_before.json').read_text())[CONFIG[problem][1]]
    p=read_params(ROOT/champ['frozen_params'])
    p['gpt_temporal']=float(variant=='tcn')
    return p

def run(job):
    problem,variant,params,seed,seconds,opts=job
    begin=time.time()
    task=importlib.import_module('tasks.'+CONFIG[problem][0]).TASK()
    task.seed=seed
    if problem=='jump':
        task.noise=opts.get('noise',0.003);task.pitch_noise=task.noise/2;task.strict=True
    if problem=='bat':
        task.seeded_pitch=False
        rng=np.random.default_rng(seed)
        task.pitches=[(float(rng.uniform(34,40.5)),float(rng.uniform(-0.14,0.15)),float(rng.uniform(0.62,1.0)))]
    baseline=opts.get('baseline',False)
    if baseline:
        champ=json.loads((OUT/'champions_before.json').read_text())[CONFIG[problem][1]]
        controller=str(ROOT/champ['frozen_controller'])
    else:controller=ctl_path(problem,variant)
    sim=Sim(task,params=params,controller=controller)
    # Instrumentation observes physics and the private diagnostic stream only.
    # No forces, activations, qpos, task metric or arena rules are changed.
    ground={i for i in range(sim.m.ngeom) if sim.m.geom_bodyid[i]==0 and sim.m.geom_type[i]==mujoco.mjtGeom.mjGEOM_PLANE}
    feet={i for i in range(sim.m.ngeom) if 'foot' in (mujoco.mj_id2name(sim.m,mujoco.mjtObj.mjOBJ_GEOM,i) or '')}
    weight=sim.m.body_subtreemass[sim.m.body('pelvis').id]*9.81
    force=np.zeros(6);state={'peak_grf_bw':0.,'peak_loading_bw_s':0.,'last_grf':0.,'fall_time':seconds}
    residual=[];qtrace=[];snap={};old_step=task.before_step;old_command=task.on_command
    def step(m,d):
        old_step(m,d)
        total=0.
        for i in range(d.ncon):
            con=d.contact[i]
            if con.geom1 not in ground and con.geom2 not in ground:continue
            other=con.geom2 if con.geom1 in ground else con.geom1
            if other in feet:
                mujoco.mj_contactForce(m,d,i,force)
                total+=abs(float(force[:3]@con.frame.reshape(3,3)[:,2]))/weight
            elif problem=='jump' and d.time>0.4:
                state['fall_time']=min(state['fall_time'],float(d.time))
        state['peak_grf_bw']=max(state['peak_grf_bw'],total)
        state['peak_loading_bw_s']=max(state['peak_loading_bw_s'],(total-state['last_grf'])/m.opt.timestep)
        state['last_grf']=total
        if not qtrace or d.time-qtrace[-1][0]>=0.0099:
            qtrace.append((float(d.time),d.qpos.copy()))
        if problem=='jump' and d.time>=3.0 and not snap:
            snap.update(task.metrics(m,d,sim.log))
    def command(m,d,cmd):
        if cmd.startswith('gptres:'):
            residual.append([float(d.time),*[float(x) for x in cmd.split(':')[1:]]])
        else:old_command(m,d,cmd)
    task.before_step=step;task.on_command=command
    try:
        metrics=sim.run(seconds)
        metrics.update({k:v for k,v in state.items() if k!='last_grf'})
        penalty=0.01*max(0.,state['peak_grf_bw']-4.)**2+0.0002*max(0.,state['peak_loading_bw_s']-100.)
        if problem=='jump':
            legal=metrics.get('takeoff') and not any(metrics.get(k) for k in ('fallen','foul','inverted'))
            score=2.*legal+max(0.,snap.get('mark',0.))+0.5*state['fall_time']/seconds-penalty
            if metrics.get('foul'):score-=3.
            metrics['three_second']=snap
        elif problem=='bat':
            score=float(metrics.get('power') or 0.)+0.25*float(metrics.get('quality') or 0.)-penalty
        else:
            score=float(metrics.get('x_ok') or 0.)+0.03*float(metrics.get('dribbles') or 0.)-0.1*float(metrics.get('body_hits') or 0.)-penalty
        rr=np.asarray(residual)
        metrics['residual_peak_rad']=np.max(np.abs(rr[:,1:]),axis=0).tolist() if len(rr) else [0.]*4
        metrics['residual_rms_rad']=np.sqrt(np.mean(rr[:,1:]**2,axis=0)).tolist() if len(rr) else [0.]*4
        if opts.get('trace'):
            trace=OUT/opts['trace'];np.savez_compressed(trace,residual=rr,t=np.array([q[0] for q in qtrace]),q=np.array([q[1] for q in qtrace]),labels=np.array([row[1] for row in sim.log]),command=np.array([row[4] for row in sim.log]),measured=np.array([row[3] for row in sim.log]),activation=np.array([row[2] for row in sim.log]))
        return float(score),jsonable(metrics),time.time()-begin
    except Exception as exc:
        return -1e9,{'error':str(exc)},time.time()-begin

class ExperimentProblem(Problem):
    def __init__(self,problem,variant,rep,seeds,seconds):
        super().__init__(CONFIG[problem][0],rep,seeds,seconds,risk=0.5)
        self.problem=problem;self.variant=variant
    def jobs(self,x,seeds=None):
        return [(self.problem,self.variant,self.rep.decode(x),seed,self.seconds,{}) for seed in (seeds or self.seeds)]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['train','validate','parity','probe'])
    ap.add_argument('problem',choices=CONFIG);ap.add_argument('variant',choices=['pure','tcn'])
    ap.add_argument('--budget',type=int,default=512);ap.add_argument('--sigma',type=float,default=.03);ap.add_argument('--method',default='oneplusone')
    ap.add_argument('--seed',type=int,default=270927);ap.add_argument('--init');ap.add_argument('--only');ap.add_argument('--tag',default='');ap.add_argument('--seeds',type=int,default=8)
    args=ap.parse_args();problem=args.problem;variant=args.variant;tag=problem+'_'+variant+args.tag
    params=initial(problem,variant)
    if args.init:params.update(read_params(args.init))
    params['gpt_temporal']=float(variant=='tcn')
    os.environ['ROBOLAB_CONTROLLER']=ctl_path(problem,variant)
    seconds=CONFIG[problem][2]
    OUT.mkdir(exist_ok=True);PARAMS.mkdir(exist_ok=True)
    with mp.get_context('spawn').Pool(3) as pool:
        if args.action=='train':
            tun=describe(CONFIG[problem][0],params)
            names=['gpt_w*']+CONFIG[problem][3]
            if args.only:names=args.only.split(',')
            rep=BoxRep.from_tunables(tun,only=names,init=params,fixed={'gpt_temporal':params['gpt_temporal']})
            prob=ExperimentProblem(problem,variant,rep,TRAIN[:args.seeds],seconds)
            search=Search(prob,args.method,args.budget,args.seed,args.sigma,out=str(PARAMS/(tag+'.txt')),log=str(OUT/(tag+'.jsonl')),archive=str(OUT/(tag+'.npz')),label='gpt:'+tag)
            print(f'{tag}: {rep.n} dimensions, {args.budget} rollouts, {args.seeds} fixed fresh training seeds',flush=True)
            while not search.done:
                jobs=search.next_jobs()
                if not jobs:break
                results=pool.map(run,jobs,chunksize=1);search.consume(results)
                if search.gen%10==0 or search.done or search.gen==1:
                    print(f'{tag} gen {search.gen} used {search.used} best {search.best[0]:.6f} wall {time.time()-search.t0:.1f}',flush=True)
            (OUT/(tag+'.json')).write_text(json.dumps(jsonable(search.summary()),indent=2)+'\n')
        elif args.action=='parity':
            # Base, pure-zero and TCN-zero on identical task state; exact controls.
            jobs=[(problem,variant,params,TRAIN[0],3. if problem=='jump' else seconds,{'baseline':b,'trace':tag+('_base' if b else '_zero')+'.npz'}) for b in [True,False]]
            results=pool.map(run,jobs)
            left=np.load(OUT/(tag+'_base.npz'));right=np.load(OUT/(tag+'_zero.npz'))
            parity={key:bool(np.array_equal(left[key],right[key])) for key in ('command','measured','activation','q')}
            report={'parity':parity,'results':results};(OUT/(tag+'_parity.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(parity),flush=True)
        else:
            if args.action=='validate':params.update(read_params(PARAMS/(tag+'.txt')))
            seeds=VALID if args.action=='validate' else TRAIN[:args.seeds]
            jobs=[]
            for seed in seeds:
                for kind in ['baseline','candidate','bias_only'] if args.action=='validate' and variant=='tcn' else ['baseline','candidate']:
                    p=dict(params)
                    if kind=='baseline':p=initial(problem,variant)
                    if kind=='bias_only':p.update({f'gpt_w{i}':0. for i in range(20) if i%5})
                    opts={'baseline':kind=='baseline'}
                    if seed==seeds[0]:opts['trace']=tag+'_'+kind+'_validation.npz'
                    jobs.append((problem,variant,p,seed,seconds,opts))
            results=pool.map(run,jobs,chunksize=1)
            report=[{'seed':j[3],'kind':'baseline' if j[5].get('baseline') else ('bias_only' if variant=='tcn' and i%3==2 and args.action=='validate' else 'candidate'),'score':res[0],'metrics':res[1],'wall':res[2]} for i,(j,res) in enumerate(zip(jobs,results))]
            (OUT/(tag+'_'+args.action+'.json')).write_text(json.dumps(report,indent=2)+'\n')
            for kind in sorted(set(row['kind'] for row in report)):
                rows=[row for row in report if row['kind']==kind];metrics=[row['metrics'] for row in rows]
                summary={'kind':kind,'score':np.mean([row['score'] for row in rows]),'errors':sum('error' in m for m in metrics)}
                for key in ['mark','fallen','foul','inverted','power','quality','x_ok','peak_grf_bw','peak_loading_bw_s']:
                    values=[m[key] for m in metrics if isinstance(m.get(key),(int,float,bool))]
                    if values:summary[key]=float(np.mean(values))
                print(json.dumps(summary),flush=True)
if __name__=='__main__':main()
