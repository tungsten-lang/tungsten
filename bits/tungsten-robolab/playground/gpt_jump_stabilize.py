"""Bounded recovery-only grid, with 32 training and 64 untouched test starts."""
import argparse,hashlib,itertools,json,multiprocessing as mp
import gpt_jump_recover as previous
from search import read_params,write_params,jsonable
ROOT=previous.ROOT;OUT=ROOT/'out/competitor_jump_round3';PARAMS=ROOT/'params/competitor_jump_round3'
TRAIN=list(range(275101,275133));VALID=list(range(276101,276165))
legal=previous.legal

def controller(v):return str(ROOT/f'bin/challengers/gpt-jump-stable-{v}')
def initial(v):return read_params(ROOT/f'params/competitor_jump_round2/{v}.txt')
def run(job):
    previous.OUT=OUT;previous.controller=controller
    return previous.run(job)
def count(ms):return {'legal8':sum(legal(m) for m in ms),'legal3':sum(legal(m['three_second']) for m in ms),'mean3':sum(m['three_second']['mark'] for m in ms)/len(ms),'mean8':sum(m['mark'] for m in ms)/len(ms)}
def key(ms):
    c=count(ms)
    smooth=sum(2*m['three_second']['mark']+m['mark']-.01*max(m['peak_grf_bw']-4.,0.)**2-.0002*max(m['peak_loading_bw_s']-100.,0.) for m in ms)/len(ms)
    return c['legal8'],c['legal3'],smooth

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['train','validate']);ap.add_argument('variant',choices=['pure','tcn']);a=ap.parse_args();p=initial(a.variant)
    with mp.get_context('spawn').Pool(3) as pool:
        if a.action=='train':
            variants=[p]+[{**p,'stand_after':t,'stand_gain':g} for t,g in itertools.product([.10,.18,.26,.34],[.6,.8,1.,1.2])]
            records=[];best=None
            for i,prm in enumerate(variants):
                jobs=[(a.variant,prm,s,8.,'candidate',None) for s in TRAIN];result=pool.map(run,jobs,chunksize=1);ms=[r[1] for r in result];assert not any('error' in m for m in ms)
                rank=key(ms);row={'index':i,'params':prm,'key':rank,'metrics':ms,'summary':count(ms),'rollout_seconds':sum(r[2] for r in result)};records.append(row)
                with open(OUT/f'{a.variant}_grid.jsonl','a') as f:f.write(json.dumps(jsonable({'index':i,'stand_after':prm['stand_after'],'stand_gain':prm['stand_gain'],'key':rank,'summary':row['summary']}))+'\n')
                if best is None or rank>tuple(best['key']):best=row
                print(a.variant,i,row['summary'],flush=True)
            write_params(str(PARAMS/f'{a.variant}.txt'),'gpt: stability '+a.variant,best['params'],float(best['key'][0]),best['metrics'])
            (OUT/f'{a.variant}.json').write_text(json.dumps(jsonable({'used':len(variants)*len(TRAIN),'selected_index':best['index'],'params':best['params'],'metrics':best['metrics'],'grid':records}),indent=2)+'\n')
        else:
            candidate=read_params(PARAMS/f'{a.variant}.txt');jobs=[]
            for s in VALID:
                for kind in (['previous','candidate','bias_only','zero_head'] if a.variant=='tcn' else ['previous','candidate']):
                    prm=dict(candidate)
                    if kind=='previous':prm=dict(p)
                    if kind=='bias_only':prm.update({f'gpt_w{i}':0. for i in range(20) if i%5})
                    if kind=='zero_head':prm.update({f'gpt_w{i}':0. for i in range(20)})
                    jobs.append((a.variant,prm,s,8.,kind,f'{a.variant}_{kind}_validation.npz' if s==VALID[0] else None))
            result=pool.map(run,jobs,chunksize=1);rows=[{'seed':j[2],'kind':j[4],'metrics':r[1],'wall':r[2]} for j,r in zip(jobs,result)]
            (OUT/f'{a.variant}_validate.json').write_text(json.dumps(jsonable(rows),indent=2)+'\n')
            for kind in sorted({r['kind'] for r in rows}):print(a.variant,kind,count([r['metrics'] for r in rows if r['kind']==kind]),flush=True)
if __name__=='__main__':main()
