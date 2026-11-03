"""Private event-triggered landing recovery; exact-off parity and matched pilot."""
import argparse,hashlib,itertools,json,multiprocessing as mp,statistics
from pathlib import Path
import numpy as np
import gpt_competitor as base
from bridge import Sim
from gpt_jump_recover import legal
from search import read_params,write_params,jsonable
ROOT=base.ROOT;OUT=ROOT/'out/competitor_jump_round5';PARAMS=ROOT/'params/competitor_jump_round5'
PARITY=[279001,279002];PILOT=list(range(279101,279109));VALID=list(range(281101,281165))

def controller(v,old=False):return str(OUT/f'reference/previous-{v}') if old else str(ROOT/f'bin/challengers/gpt-jump-adaptive-{v}')
def initial(v):return read_params(OUT/f'reference/previous-{v}.txt')
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')

class CaptureSim(Sim):
    def __init__(self,*args,**kwargs):
        self.capture_events=[];self.sensor_samples=[]
        super().__init__(*args,**kwargs)
    def standard_sensors(self):
        blocks=super().standard_sensors();b=dict(blocks)
        phase=getattr(self,'label','')
        if 'land' in phase:
            up=b['torso_up'];self.sensor_samples.append([float(self.d.time),float(b['pelvis_pos'][2]),float(np.arctan2(up[0],up[2])),float(b['torso_angvel'][1]),float(b['com_vel'][0]),phase])
        return blocks
    def run(self,seconds=None,recorder=None):
        old_command=self.task.on_command
        def command(m,d,cmd):
            if cmd.startswith('gptcatch:'):self.capture_events.append([float(x) for x in cmd.split(':')[1:]])
            else:old_command(m,d,cmd)
        self.task.on_command=command
        result=super().run(seconds,recorder)
        transitions=[];last=None
        for time,label,*_ in self.log:
            if label!=last:transitions.append([float(time),label]);last=label
        result.update(capture_events=self.capture_events,phase_transitions=transitions,landing_sensors=self.sensor_samples)
        return result

def run(job):
    v,p,seed,seconds,old,trace=job
    base.OUT=OUT;base.Sim=CaptureSim;base.ctl_path=lambda task,mode:controller(mode,old)
    _,m,wall=base.run(('jump',v,p,seed,seconds,{'trace':trace} if trace else {}))
    if 'error' in m:return -1e9,m,wall
    penalty=.01*max(m['peak_grf_bw']-4.,0.)**2+.0002*max(m['peak_loading_bw_s']-100.,0.)
    score=100*legal(m)+20*legal(m['three_second'])+2*max(m['three_second'].get('mark',0),0)+.5*max(m.get('mark',0),0)*legal(m)-penalty
    return score,m,wall

def summary(rows):
    ms=[r[1] for r in rows];good3=[m['three_second'] for m in ms if legal(m['three_second'])];good8=[m for m in ms if legal(m)]
    return {'n':len(ms),'legal3':len(good3),'legal8':len(good8),'mark3':statistics.mean(m['mark'] for m in good3) if good3 else None,'mark8':statistics.mean(m['mark'] for m in good8) if good8 else None,'mean_peak_bw':statistics.mean(m['peak_grf_bw'] for m in ms),'capture_count':sum(bool(m['capture_events']) for m in ms)}

def candidates(v):
    p=initial(v)
    yield {'kind':'unchanged','params':{**p,'gpt_capture':0.}}
    for minimum,pitch,height in itertools.product([.12,.18,.24],[.65,.85,1.05,1.25],[.48,.56,.64]):
        yield {'kind':'adaptive','params':{**p,'gpt_capture':1.,'gpt_capture_min':minimum,'gpt_capture_pitch':pitch,'gpt_capture_height':height,'gpt_capture_back':.3,'gpt_capture_look':.12}}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['parity','pilot']);a=ap.parse_args()
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='parity':
            jobs=[(v,{**initial(v),'gpt_capture':0.},s,8.,old,f'parity_{v}_{s}_{"old" if old else "off"}.npz') for v in ['pure','tcn'] for s in PARITY for old in [True,False]]
            results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results),results
            checks=[]
            for v in ['pure','tcn']:
                for seed in PARITY:
                    left=np.load(OUT/f'parity_{v}_{seed}_old.npz');right=np.load(OUT/f'parity_{v}_{seed}_off.npz')
                    equal={k:np.array_equal(left[k],right[k]) for k in ['residual','t','q','labels','command','measured','activation']}
                    checks.append({'variant':v,'seed':seed,'exact':equal});assert all(equal.values()),checks[-1]
            write('parity.json',{'checks':checks,'passed':True,'jobs':[{'variant':j[0],'seed':j[2],'old':j[4],'metrics':r[1]} for j,r in zip(jobs,results)]})
            print('PASS: four eight-second old/off pairs match exactly in commands, measured motion, activations, q and residuals',flush=True)
        else:
            assert json.loads((OUT/'parity.json').read_text())['passed']
            selected={}
            for v in ['pure','tcn']:
                records=[]
                for index,candidate in enumerate(candidates(v)):
                    jobs=[(v,candidate['params'],s,8.,False,f'{v}_pilot_{index}.npz' if s==PILOT[0] else None) for s in PILOT]
                    results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results),results
                    scores=[r[0] for r in results];score=.5*(statistics.mean(scores)+min(scores))
                    row={'index':index,**candidate,'score':score,'summary':summary(results),'rows':[{'seed':j[2],'metrics':r[1],'score':r[0]} for j,r in zip(jobs,results)]};records.append(row)
                    with (OUT/f'{v}_pilot.jsonl').open('a') as f:f.write(json.dumps(jsonable(row))+'\n')
                    print(v,index,json.dumps(row['summary']),round(score,6),flush=True)
                assert len(records)==37
                best=max(records,key=lambda r:r['score'])
                write_params(PARAMS/f'{v}.txt','gpt: adaptive recovery pilot '+v,best['params'],best['score'],best['summary'])
                selected[v]={'selected':best['index'],'params':best['params'],'summary':best['summary'],'used':37*len(PILOT),'baseline':records[0]['summary']}
                write(v+'_pilot.json',records);write('pilot_summary.json',selected)
            print('FINAL',json.dumps(selected),flush=True)
if __name__=='__main__':main()
