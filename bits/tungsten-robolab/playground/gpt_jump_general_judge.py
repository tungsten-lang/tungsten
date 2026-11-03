"""Fresh endurance, exact P6 replay, then unchanged arena decisions for R4."""
import hashlib,json,multiprocessing as mp,subprocess,sys
from pathlib import Path
import arena
import gpt_competitor as base
from gpt_jump_generalize import ROOT,OUT,PARAMS,VALID,TRAIN,BUDGET,controller,initial,run,legal,stats,read_params
TRIALS=['search_jump_legal','search_jump_robust_legal','gpt_jump_stable6']
def write(name,data):(OUT/name).write_text(json.dumps(data,indent=2)+'\n')
def read(name):return json.loads((OUT/name).read_text())
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def invoke(args,log):
    with (OUT/log).open('w') as f:subprocess.run([sys.executable,*args],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True)
def reference(seed):
    base.OUT=OUT;base.ctl_path=lambda task,mode:str(OUT/'reference/p6-controller')
    p=read_params(OUT/'reference/p6-params.txt')
    return base.run(('jump','pure',p,seed,8.,{'trace':'p6_reference_validation.npz'} if seed==VALID[0] else {}))
def main():
    before=read('champions_before.json');main_before=read('main_champions_before.json');current=json.loads((ROOT/'playground/arena/champions.json').read_text())
    for t in TRIALS:assert current[t]['scores']==before[t]['scores']
    trials=json.loads((ROOT/'playground/arena/trials.json').read_text());assert (ROOT/'playground/arena/trials.json').read_bytes()==(OUT/'trials_before.json').read_bytes()
    for v in ['pure','tcn']:
        train=read(v+'.json');assert train['used']==BUDGET
        assert all(train['params'].get(f'gpt_w{i}',0)==initial(v).get(f'gpt_w{i}',0) for i in range(20))
        rows=read(v+'_validate.json');assert {r['seed'] for r in rows if r['kind']=='candidate'}==set(VALID)
        assert not any('error' in r['metrics'] for r in rows)
    manifest=read('reference/manifest.json')
    for p,h in manifest['files'].items():assert digest(OUT/p)==h
    t='search_jump_robust_legal';tr=trials[t]
    assert tr==read('main_trials_before.json')[t]
    rows,scores=arena.evaluate(tr,read_params(OUT/'reference/p6-params.txt'),str(OUT/'reference/p6-controller'),tr['task'],3)
    assert scores==main_before[t]['scores'],{'P6 replay drift':scores,'stored':main_before[t]['scores']}
    write('p6_arena_replay.json',{'trial':tr,'rows':rows,'scores':scores,'exact_replay':True})
    print('P6 robust reference replay exact',sum(scores)/len(scores),flush=True)
    with mp.get_context('spawn').Pool(3) as pool:
        rr=pool.map(reference,VALID,chunksize=1);assert not any('error' in r[1] for r in rr)
        refrows=[{'seed':s,'metrics':r[1],'wall':r[2]} for s,r in zip(VALID,rr)];write('p6_validate.json',refrows)
        print('P6 fresh',stats([r['metrics'] for r in refrows]),flush=True)
        jobs=[(v,read_params(PARAMS/f'{v}.txt'),s,20.,'candidate',f'{v}_20sec.npz' if s==VALID[0] else None) for v in ['pure','tcn'] for s in VALID[:8]]
        rr=pool.map(run,jobs,chunksize=1);assert not any('error' in r[1] for r in rr)
        endurance=[{'variant':j[0],'seed':j[2],'metrics':r[1],'wall':r[2]} for j,r in zip(jobs,rr)];write('endurance20.json',endurance)
        for v in ['pure','tcn']:print('20 seconds',v,stats([r['metrics'] for r in endurance if r['variant']==v]),flush=True)
    entries=[];head=[]
    for t in TRIALS:
        saved={}
        for v in ['pure','tcn']:
            artifact=OUT/f'arena_{v}_{t}.json'
            invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',t,'--params',str(PARAMS/f'{v}.txt'),'--controller',controller(v),'--note',f'gpt: general recovery {v}; 3072 equal-budget rollouts, 16 fresh training starts, 64 held-out validations, inherited bounded head frozen','--workers','3'],f'arena_{v}_{t}.log')
            d=read(artifact.name);saved[v]=d;valid=[s for s in d['scores'] if abs(s)<1e8]
            local=arena.compare(d['trial'],before[t]['scores'],d['scores']);frontier=arena.compare(d['trial'],main_before[t]['scores'],d['scores']) if t in main_before else None
            row={'trial':t,'variant':v,'local':local,'main_frontier':frontier,'passes':len(valid),'n':len(d['scores']),'mean_valid':sum(valid)/len(valid) if valid else None,'mean_guard_coded':sum(d['scores'])/len(d['scores'])};entries.append(row);print(json.dumps(row),flush=True)
        head.append({'trial':t,**arena.compare(saved['tcn']['trial'],saved['pure']['scores'],saved['tcn']['scores'])})
    write('arena_summary.json',{'entries':entries,'tcn_vs_pure':head});promotions=[]
    for t in TRIALS:
        eligible=[r for r in entries if r['trial']==t and r['local']['wins'] and (r['main_frontier'] is None or r['main_frontier']['wins'])]
        if not eligible:continue
        best=max(eligible,key=lambda r:r['mean_guard_coded']);v=best['variant'];artifact=OUT/f'promoted_{t}.json'
        invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',t,'--params',str(PARAMS/f'{v}.txt'),'--controller',controller(v),'--note',f'gpt: general recovery {v}; beats local and recorded main frontier, matched budget and 64 fresh validations','--workers','3','--promote'],f'promoted_{t}.log')
        c=json.loads((ROOT/'playground/arena/champions.json').read_text())[t];assert c['result']=='promoted' and c['note'].startswith('gpt:')
        assert digest(ROOT/c['frozen_controller'])==digest(controller(v)) and digest(ROOT/c['frozen_params'])==digest(PARAMS/f'{v}.txt')
        d=read(artifact.name);valid=[i for i,s in enumerate(d['scores']) if abs(s)<1e8];i=min(valid,key=lambda i:abs(d['scores'][i]-best['mean_valid']));seed=d['trial']['seeds'][i];stem=OUT/f'video_{t}_{v}'
        invoke(['playground/gpt_render.py',t,'--params',c['frozen_params'],'--controller',c['frozen_controller'],'--seed',str(seed),'--seconds','20','--out',str(stem)],f'video_{t}_{v}.log')
        promotions.append({**best,'champion':c,'seed':seed,'video':str(stem)+'.mp4','sheet':str(stem)+'_sheet.png'});write('promotions.json',promotions);print('Promoted and rendered',t,v,flush=True)
    if not promotions:write('promotions.json',[])
    if promotions:invoke(['playground/arena.py','recheck',*[r['trial'] for r in promotions],'--workers','3'],'recheck_promoted.log')
if __name__=='__main__':main()
