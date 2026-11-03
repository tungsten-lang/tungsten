"""Matched original replay and longer-horizon checks; no parameter selection."""
import json,multiprocessing as mp
import gpt_competitor as base
from gpt_jump_recover import ROOT,OUT,PARAMS,VALID,run,legal,read_params

def original(seed):
    base.OUT=OUT
    return base.run(('jump','pure',base.initial('jump','pure'),seed,8.,{'baseline':True,**({'trace':'original_validation.npz'} if seed==VALID[0] else {})}))
def main():
    with mp.get_context('spawn').Pool(3) as pool:
        results=pool.map(original,VALID,chunksize=1)
        rows=[{'seed':s,'metrics':r[1],'wall':r[2]} for s,r in zip(VALID,results)]
        (OUT/'original_validate.json').write_text(json.dumps(rows,indent=2)+'\n')
        print('original',sum(legal(r['metrics']) for r in rows),'/',len(rows),'legal8',flush=True)
        jobs=[(v,read_params(PARAMS/f'{v}.txt'),s,20.,'candidate',f'{v}_20sec.npz' if s==VALID[0] else None) for v in ['pure','tcn'] for s in VALID[:8]]
        results=pool.map(run,jobs,chunksize=1)
        rows=[{'variant':j[0],'seed':j[2],'metrics':r[1],'wall':r[2]} for j,r in zip(jobs,results)]
        (OUT/'endurance20.json').write_text(json.dumps(rows,indent=2)+'\n')
        for v in ['pure','tcn']:
            group=[r['metrics'] for r in rows if r['variant']==v]
            print(v,sum(legal(m) for m in group),'/',len(group),'legal20',flush=True)
if __name__=='__main__':main()
