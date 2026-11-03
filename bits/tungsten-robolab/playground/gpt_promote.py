"""Promote only previously judged arena winners, then render frozen copies."""
import hashlib,json,subprocess,sys
from pathlib import Path
from gpt_summarize import OUT,ROOT
from gpt_competitor import ctl_path

def invoke(args,log):
    with open(OUT/log,'w') as stream:
        subprocess.run([sys.executable,*args],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,check=True)

def main():
    summary=json.loads((OUT/'summary.json').read_text());winners=[]
    for trial in sorted({r['trial'] for r in summary['arena']}):
        eligible=[r for r in summary['arena'] if r['trial']==trial and r['wins']]
        if not eligible:continue
        chosen=max(eligible,key=lambda r:r['mean_guard_coded']);problem=chosen['problem'];variant=chosen['variant']
        controller=str(Path(ctl_path(problem,variant)).relative_to(ROOT));params=f'params/competitor_20260927/{problem}_{variant}.txt'
        artifact=f'out/competitor_20260927/promoted_{trial}.json'
        invoke(['playground/gpt_arena_entry.py','--artifact',artifact,'eval',trial,'--params',params,'--controller',controller,'--note',f'gpt: {problem} {variant}; matched-budget campaign winner, fresh validation and full-motion diagnostics recorded','--workers','3','--promote'],f'promoted_{trial}.log')
        champs=json.loads((ROOT/'playground/arena/champions.json').read_text());champ=champs[trial]
        if not champ.get('note','').startswith('gpt:') or champ.get('result')!='promoted':
            raise RuntimeError('Arena did not promote requested candidate: '+trial)
        for current,frozen in [(controller,champ['frozen_controller']),(params,champ['frozen_params'])]:
            if hashlib.sha256((ROOT/current).read_bytes()).digest()!=hashlib.sha256((ROOT/frozen).read_bytes()).digest():
                raise RuntimeError('Promoted artifact differs from selected candidate: '+trial)
        d=json.loads((ROOT/artifact).read_text());eligible_idx=[i for i,v in enumerate(d['scores']) if abs(v)<1e8]
        if problem=='bat':eligible_idx=[i for i in eligible_idx if d['rows'][i].get('hits',0)>0]
        mean=sum(d['scores'][i] for i in eligible_idx)/len(eligible_idx)
        idx=min(eligible_idx,key=lambda i:abs(d['scores'][i]-mean));seed=d['trial']['seeds'][idx]
        stem=f'out/competitor_20260927/video_{trial}_{variant}'
        args=['playground/gpt_render.py',trial,'--params',champ['frozen_params'],'--controller',champ['frozen_controller'],'--seed',str(seed),'--out',stem]
        if problem=='jump':args+=['--seconds','12']
        invoke(args,f'video_{trial}_{variant}.log')
        record={**chosen,'champion':champ,'video':str(ROOT/(stem+'.mp4')),'sheet':str(ROOT/(stem+'_sheet.png')),'seed':seed}
        if problem=='jump':
            failing=[i for i,v in enumerate(d['scores']) if abs(v)>=1e8]
            if failing:
                fail_seed=d['trial']['seeds'][failing[0]];failstem=stem+'_failure'
                invoke(['playground/gpt_render.py',trial,'--params',champ['frozen_params'],'--controller',champ['frozen_controller'],'--seed',str(fail_seed),'--out',failstem,'--seconds','12'],f'video_{trial}_{variant}_failure.log')
                record['failure_video']=str(ROOT/(failstem+'.mp4'));record['failure_seed']=fail_seed
        winners.append(record)
        (OUT/'promotions.json').write_text(json.dumps(winners,indent=2)+'\n')
        print('Promoted and rendered',trial,variant,flush=True)
    if not winners:(OUT/'promotions.json').write_text('[]\n')
if __name__=='__main__':main()
