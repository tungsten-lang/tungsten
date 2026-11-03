"""Check nonzero residuals change commanded AND measured motion for all skills."""
import json,multiprocessing as mp
import numpy as np
from gpt_competitor import OUT,CONFIG,initial,run

def main():
    jobs=[]
    for problem in CONFIG:
        for variant in ['pure','tcn']:
            for kind in ['zero','nonzero']:
                p=initial(problem,variant);p.update({f'gpt_w{i}':0. for i in range(20)})
                if kind=='nonzero':
                    p.update({f'gpt_w{i}':.25 for i in [0,5,10,15,1,6,11,16]})
                jobs.append((problem,variant,p,270999,CONFIG[problem][2],{'trace':f'integration_{problem}_{variant}_{kind}.npz'}))
    with mp.get_context('spawn').Pool(3) as pool:results=pool.map(run,jobs,chunksize=1)
    report=[]
    for i in range(0,len(jobs),2):
        problem,variant=jobs[i][:2];a=np.load(OUT/f'integration_{problem}_{variant}_zero.npz');b=np.load(OUT/f'integration_{problem}_{variant}_nonzero.npz')
        diff={key:float(np.max(np.abs(a[key]-b[key]))) for key in ['command','measured','q']}
        report.append({'problem':problem,'variant':variant,'max_absolute_difference':diff,'errors':[r[1]['error'] for r in results[i:i+2] if 'error' in r[1]]})
    (OUT/'integration.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
    assert all(not r['errors'] and all(v>1e-8 for v in r['max_absolute_difference'].values()) for r in report)
if __name__=='__main__':main()
