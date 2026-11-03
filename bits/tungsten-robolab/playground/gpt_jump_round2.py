"""Private second jump campaign: diagnose sensed touchdown, never edit arena."""
import json,multiprocessing as mp
from pathlib import Path
import gpt_competitor as base
ROOT=base.ROOT
OUT=ROOT/'out/competitor_jump_round2'
TRAIN=list(range(273101,273109))
VALID=list(range(274101,274133))

def execute(job):
    name,p,seed,seconds,trace=job
    base.OUT=OUT
    res=base.run(('jump','pure',p,seed,seconds,{'trace':trace} if trace else {}))
    return {'name':name,'seed':seed,'score':res[0],'metrics':res[1],'wall':res[2]}
def legal(m):return bool(m.get('takeoff')) and not any(m.get(k) for k in ['fallen','foul','inverted'])
def main():
    p=base.initial('jump','pure')
    configs={'original':p,'touch85':{**p,'td_z':.85},'touch105':{**p,'td_z':1.05},'touch_off':{**p,'fb_touch':0.}}
    flight={**p,**{k.replace('flight_c_','land_c_'):v for k,v in p.items() if k.startswith('flight_c_')},'td_z':.85,'g_land':1.}
    configs['hold_flight']=flight
    capture={'td_z':.85,'k_la':1.5,'k_lh':1.5,'k_lk':0.,'k_ls':0.,'k_larm':2.,'k_lp':0.,'kd_lp':0.,'d_land':.06,'p_land':1.}
    configs['capture']={**p,**capture}
    configs['capture_flight']={**flight,**capture}
    configs['rise']={**p,**capture,'fb_stand':1.,'stand_after':.3,'stand_t':.6,'stand_gain':.8}
    jobs=[(name,params,seed,8.,f'probe_{name}.npz' if seed==TRAIN[0] else None) for name,params in configs.items() for seed in TRAIN]
    with mp.get_context('spawn').Pool(3) as pool:rows=pool.map(execute,jobs,chunksize=1)
    (OUT/'probes.json').write_text(json.dumps(rows,indent=2)+'\n');(OUT/'probe_params.json').write_text(json.dumps(configs,indent=2)+'\n')
    for name in configs:
        ms=[r['metrics'] for r in rows if r['name']==name]
        print(name,{'legal8':sum(legal(m) for m in ms),'legal3':sum(legal(m.get('three_second',{})) for m in ms),'mean3':sum(m['three_second'].get('mark',0.) for m in ms)/len(ms),'fall_time':sum(m['fall_time'] for m in ms)/len(ms),'force':sum(m['peak_grf_bw'] for m in ms)/len(ms)},flush=True)
if __name__=='__main__':main()
