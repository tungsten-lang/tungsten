"""Read-only diagnostics of already-consumed R7 starts; never fresh validation."""
import json,multiprocessing as mp
from pathlib import Path
import numpy as np
import gpt_competitor as base
from gpt_jump_adaptive import CaptureSim
from search import read_params,jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_jump_round8'
SEEDS=[285101,285102,285122,285123,285150,285152,285154,285157,285160]
class SettleSim(CaptureSim):
    def __init__(self,*args,**kwargs):self.settle_samples=[];super().__init__(*args,**kwargs)
    def standard_sensors(self):
        blocks=super().standard_sensors();b=dict(blocks);t=float(self.d.time)
        if t>=1.5 and (not self.settle_samples or t-self.settle_samples[-1]['time']>=.0499):
            z=max(.3,float(b['com_pos'][2]));feet=.5*(b['l_foot_pos'][0]+b['r_foot_pos'][0]);pitch=float(np.arctan2(b['torso_up'][0],b['torso_up'][2]))
            self.settle_samples.append({'time':t,'phase':getattr(self,'label',''),'pelvis_z':float(b['pelvis_pos'][2]),'com_z':z,'com_vx':float(b['com_vel'][0]),'com_minus_feet':float(b['com_pos'][0]-feet),'capture_minus_feet':float(b['com_pos'][0]-feet+b['com_vel'][0]*np.sqrt(z/9.81)),'pitch':pitch,'pitch_rate':float(b['torso_angvel'][1])})
        return blocks
    def run(self,*args,**kwargs):
        result=super().run(*args,**kwargs);result['settle_samples']=self.settle_samples;return result

def run(job):
    v,seed=job;base.OUT=OUT;base.Sim=SettleSim;base.ctl_path=lambda task,mode:str(ROOT/f'bin/challengers/gpt-jump-mean-refine-{mode}')
    p=read_params(ROOT/f'params/competitor_jump_round7/{v}_frozen.txt')
    _,m,wall=base.run(('jump',v,p,seed,8.,{}));assert 'error' not in m,m
    return {'variant':v,'seed':seed,'metrics':m}
if __name__=='__main__':
    with mp.get_context('spawn').Pool(3) as pool:rows=pool.map(run,[(v,s) for v in ['pure','tcn'] for s in SEEDS],chunksize=1)
    (OUT/'diagnosis.json').write_text(json.dumps(jsonable({'scope':'Previously consumed round-seven starts, diagnostic only','rows':rows}),indent=2)+'\n')
    for r in rows:
        m=r['metrics'];samples=m['settle_samples'];at=lambda t:min(samples,key=lambda s:abs(s['time']-t))
        print(json.dumps({'variant':r['variant'],'seed':r['seed'],'fallen':m['fallen'],'fall_time':m['fall_time'],'at3':at(3.),'at4':at(4.)}),flush=True)
