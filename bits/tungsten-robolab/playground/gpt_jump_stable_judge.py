"""Enter both frozen recovery challengers before promoting any trial winner."""
import hashlib,json,subprocess,sys
from pathlib import Path
import arena
from gpt_jump_stabilize import ROOT,OUT,PARAMS,controller,VALID
TRIALS=['search_jump_legal','search_jump_robust_legal','gpt_jump_stable6']
def invoke(args,log):
    with open(OUT/log,'w') as f:subprocess.run([sys.executable,*args],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True)
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    before=json.loads((OUT/'champions_before.json').read_text());now=json.loads((ROOT/'playground/arena/champions.json').read_text())
    for trial in TRIALS:assert now[trial]['scores']==before[trial]['scores'],'Champion changed before comparison: '+trial
    for v in ['pure','tcn']:
        train=json.loads((OUT/f'{v}.json').read_text());assert train['used']==544
        val=json.loads((OUT/f'{v}_validate.json').read_text());candidate=[r for r in val if r['kind']=='candidate'];assert {r['seed'] for r in candidate}==set(VALID)
        assert not any('error' in r['metrics'] for r in val)
    assert (ROOT/'playground/arena/trials.json').read_bytes()==(OUT/'trials_before.json').read_bytes()
    results=[];head=[]
    for trial in TRIALS:
        saved={}
        for v in ['pure','tcn']:
            artifact=OUT/f'arena_{v}_{trial}.json'
            invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',trial,'--params',str(PARAMS/f'{v}.txt'),'--controller',controller(v),'--note',f'gpt: stability {v}; early touchdown, balanced-crouch keyframe, 544 recovery-grid rollouts on 32 starts and 64 fresh validations','--workers','3'],f'arena_{v}_{trial}.log')
            d=json.loads(artifact.read_text());saved[v]=d;comp=arena.compare(d['trial'],before[trial]['scores'],d['scores']);valid=[s for s in d['scores'] if abs(s)<1e8]
            row={'trial':trial,'variant':v,**comp,'passes':len(valid),'mean_valid':sum(valid)/len(valid) if valid else None,'mean_guard_coded':sum(d['scores'])/len(d['scores'])};results.append(row);print(json.dumps(row),flush=True)
        head.append({'trial':trial,**arena.compare(saved['tcn']['trial'],saved['pure']['scores'],saved['tcn']['scores'])})
    (OUT/'arena_summary.json').write_text(json.dumps({'entries':results,'tcn_vs_pure':head},indent=2)+'\n')
    promotions=[]
    for trial in TRIALS:
        eligible=[r for r in results if r['trial']==trial and r['wins']]
        if not eligible:continue
        best=max(eligible,key=lambda r:r['mean_guard_coded']);v=best['variant'];artifact=OUT/f'promoted_{trial}.json'
        invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',trial,'--params',str(PARAMS/f'{v}.txt'),'--controller',controller(v),'--note',f'gpt: stability {v}; matched-budget winner, fresh validation and longer-horizon diagnostics','--workers','3','--promote'],f'promoted_{trial}.log')
        champ=json.loads((ROOT/'playground/arena/champions.json').read_text())[trial]
        assert champ['result']=='promoted' and champ['note'].startswith('gpt:')
        assert digest(ROOT/champ['frozen_controller'])==digest(controller(v))
        assert digest(ROOT/champ['frozen_params'])==digest(PARAMS/f'{v}.txt')
        d=json.loads(artifact.read_text());valid=[i for i,s in enumerate(d['scores']) if abs(s)<1e8];mean=sum(d['scores'][i] for i in valid)/len(valid);i=min(valid,key=lambda i:abs(d['scores'][i]-mean));seed=d['trial']['seeds'][i]
        stem=OUT/f'video_{trial}_{v}'
        invoke(['playground/gpt_render.py',trial,'--params',champ['frozen_params'],'--controller',champ['frozen_controller'],'--seed',str(seed),'--seconds','20','--out',str(stem)],f'video_{trial}_{v}.log')
        promotions.append({**best,'champion':champ,'seed':seed,'video':str(stem)+'.mp4','sheet':str(stem)+'_sheet.png'})
        (OUT/'promotions.json').write_text(json.dumps(promotions,indent=2)+'\n');print('Promoted and rendered',trial,v,flush=True)
    if not promotions:(OUT/'promotions.json').write_text('[]\n')
if __name__=='__main__':main()
