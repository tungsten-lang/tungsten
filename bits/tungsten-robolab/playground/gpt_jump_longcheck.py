"""Longer observation of the frozen jump finalists; no training or selection."""
import json,multiprocessing as mp
from gpt_competitor import OUT,PARAMS,VALID,run,read_params,initial
if __name__=='__main__':
    jobs=[];labels=[]
    for kind in ['baseline','pure','tcn']:
        variant='pure' if kind=='baseline' else kind
        p=initial('jump',variant) if kind=='baseline' else read_params(PARAMS/('jump_'+variant+'.txt'))
        for seed in VALID[:8]:
            opts={'baseline':kind=='baseline'}
            if seed==VALID[0]:opts['trace']='jump_'+kind+'_12sec.npz'
            jobs.append(('jump',variant,p,seed,12.,opts));labels.append(kind)
    with mp.get_context('spawn').Pool(3) as pool:rows=pool.map(run,jobs,chunksize=1)
    report=[{'kind':kind,'seed':job[3],'metrics':result[1],'wall':result[2]} for kind,job,result in zip(labels,jobs,rows)]
    (OUT/'jump_12sec.json').write_text(json.dumps(report,indent=2)+'\n')
    for kind in ['baseline','pure','tcn']:
        group=[r['metrics'] for r in report if r['kind']==kind]
        passed=[m for m in group if m.get('takeoff') and not any(m.get(k) for k in ['fallen','foul','inverted'])]
        print(kind,'legal 12-second landings',len(passed),'/',len(group),'marks',[m['mark'] for m in passed],flush=True)
