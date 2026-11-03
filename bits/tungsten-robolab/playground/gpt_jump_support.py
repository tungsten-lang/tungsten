"""Private landing-depth recovery; retain the distance policy on shallow landings."""
import argparse,hashlib,itertools,json,multiprocessing as mp,statistics
from pathlib import Path
import numpy as np
import gpt_competitor as base
from bridge import Sim
from gpt_jump_recover import legal
from search import read_params,write_params,jsonable
ROOT=base.ROOT;REFERENCE=ROOT/'out/competitor_jump_round5/reference';OUT=ROOT/'out/competitor_jump_round5/support';PARAMS=ROOT/'params/competitor_jump_round5/support'
PARITY=[279001,279002];PILOT=list(range(279101,279109));VALID=list(range(281101,281165))

def controller(v,old=False):return str(REFERENCE/f'previous-{v}') if old else str(ROOT/f'bin/challengers/gpt-jump-support-{v}')
def initial(v):return read_params(REFERENCE/f'previous-{v}.txt')
def write(name,data):(OUT/name).write_text(json.dumps(jsonable(data),indent=2)+'\n')

from gpt_jump_adaptive import CaptureSim

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
    yield {'kind':'unchanged','params':{**p,'gpt_support':0.}}
    for delay,height,gain in itertools.product([.14,.18,.22],[.575,.585,.595,.605,.615],[.8,1.,1.2]):
        yield {'kind':'support','params':{**p,'gpt_support':1.,'gpt_support_time':delay,'gpt_support_height':height,'gpt_support_gain':gain}}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['parity','pilot','validate']);a=ap.parse_args()
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='parity':
            jobs=[(v,{**initial(v),'gpt_support':0.},s,8.,old,f'parity_{v}_{s}_{"old" if old else "off"}.npz') for v in ['pure','tcn'] for s in PARITY for old in [True,False]]
            results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results),results
            checks=[]
            for v in ['pure','tcn']:
                for seed in PARITY:
                    left=np.load(OUT/f'parity_{v}_{seed}_old.npz');right=np.load(OUT/f'parity_{v}_{seed}_off.npz')
                    equal={k:np.array_equal(left[k],right[k]) for k in ['residual','t','q','labels','command','measured','activation']}
                    checks.append({'variant':v,'seed':seed,'exact':equal});assert all(equal.values()),checks[-1]
            write('parity.json',{'checks':checks,'passed':True,'jobs':[{'variant':j[0],'seed':j[2],'old':j[4],'metrics':r[1]} for j,r in zip(jobs,results)]})
            print('PASS: four eight-second old/off pairs match exactly in commands, measured motion, activations, q and residuals',flush=True)
        elif a.action=='pilot':
            assert json.loads((OUT/'parity.json').read_text())['passed']
            selected={}
            for v in ['pure','tcn']:
                records=[]
                for index,candidate in enumerate(candidates(v)):
                    jobs=[(v,candidate['params'],s,8.,False,f'{v}_pilot_{index}.npz' if s==PILOT[1] else None) for s in PILOT]
                    results=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in results),results
                    scores=[r[0] for r in results];score=.5*(statistics.mean(scores)+min(scores))
                    row={'index':index,**candidate,'score':score,'summary':summary(results),'rows':[{'seed':j[2],'metrics':r[1],'score':r[0]} for j,r in zip(jobs,results)]};records.append(row)
                    with (OUT/f'{v}_pilot.jsonl').open('a') as f:f.write(json.dumps(jsonable(row))+'\n')
                    print(v,index,json.dumps(row['summary']),round(score,6),flush=True)
                assert len(records)==46
                best=max(records,key=lambda r:r['score'])
                write_params(PARAMS/f'{v}.txt','gpt: landing-depth recovery pilot '+v,best['params'],best['score'],best['summary'])
                selected[v]={'selected':best['index'],'params':best['params'],'summary':best['summary'],'used':46*len(PILOT),'baseline':records[0]['summary']}
                eligible=[r for r in records if r['summary']['legal3']==len(PILOT) and r['summary']['legal8']>=6]
                if eligible:
                    distance=max(eligible,key=lambda r:(r['summary']['mark3'],r['score']))
                    write_params(PARAMS/f'{v}_distance.txt','gpt: landing-depth distance candidate '+v,distance['params'],distance['score'],distance['summary'])
                    selected[v]['distance_alternative']={'selected':distance['index'],'params':distance['params'],'summary':distance['summary'],'same_as_recovery':distance['params']==best['params']}
                write(v+'_pilot.json',records);write('pilot_summary.json',selected)
            print('FINAL',json.dumps({v:{'recovery':row['summary'],'distance':row.get('distance_alternative',{}).get('summary'),'used':row['used']} for v,row in selected.items()}),flush=True)
        else:
            for v in ['pure','tcn']:
                p=read_params(PARAMS/f'{v}.txt');kinds=['previous','candidate','static_support']+(['bias_only','zero_head'] if v=='tcn' else [])
                jobs=[];metadata=[]
                for seed in VALID:
                    for kind in kinds:
                        prm=dict(p)
                        if kind=='previous':prm={**initial(v),'gpt_support':0.}
                        if kind=='static_support':prm.update(gpt_support=0.,stand_after=p.get('gpt_support_time',p['stand_after']),stand_gain=p.get('gpt_support_gain',p['stand_gain']))
                        if kind=='bias_only':prm.update({f'gpt_w{i}':0. for i in range(20) if i%5})
                        if kind=='zero_head':prm.update({f'gpt_w{i}':0. for i in range(20)})
                        jobs.append((v,prm,seed,8.,False,f'{v}_{kind}_validation.npz' if seed==VALID[0] else None));metadata.append(kind)
                results=pool.map(run,jobs,chunksize=1);assert not any('error' in row[1] for row in results)
                rows=[{'seed':j[2],'kind':kind,'metrics':res[1],'score':res[0]} for j,kind,res in zip(jobs,metadata,results)]
                write(v+'_validate.json',rows)
                for kind in kinds:print(v,kind,json.dumps(summary([res for name,res in zip(metadata,results) if name==kind])),flush=True)
if __name__=='__main__':main()
