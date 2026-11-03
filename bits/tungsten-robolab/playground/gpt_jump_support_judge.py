"""Arena decisions for all frozen landing-depth candidates; no trial edits."""
import json,subprocess,sys
from pathlib import Path
import arena
from gpt_jump_support_validate import ROOT,OUT,VALID,read,write,sha,check_frozen
TRIALS=['search_jump_legal','search_jump_robust_legal','gpt_jump_stable6']
ROUND=OUT.parent

def invoke(args,log):
    with (OUT/log).open('w') as f:subprocess.run([sys.executable,*args],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True)

def main():
    registry=check_frozen();before=read(ROUND/'champions_before.json');main_before=read(ROUND/'main_champions_before.json');trials=read(ROOT/'playground/arena/trials.json')
    assert (ROOT/'playground/arena/trials.json').read_bytes()==(ROUND/'trials_before.json').read_bytes()
    board=read(ROOT/'playground/arena/champions.json')
    for t in TRIALS:assert board[t]['scores']==before[t]['scores'],t
    main_now=read('/Users/erik/tungsten/bits/tungsten-robolab/playground/arena/champions.json')
    for t in ['search_jump_legal','search_jump_robust_legal']:assert main_now[t]['scores']==main_before[t]['scores'],'Main frontier changed: '+t
    validation=read(OUT/'validation.json');long=read(OUT/'endurance20.json')
    assert not any('error' in row['metrics'] for row in validation+long)
    for r in registry:
        assert {x['seed'] for x in validation if x['label']==r['label']}==set(VALID)
        assert {x['seed'] for x in long if x['label']==r['label']}==set(VALID[:8])
    # A fresh exact reference replay also checks that private instrumentation
    # and the ordinary arena remain comparable under the pinned body/task.
    t='search_jump_robust_legal';ref=ROOT/'out/competitor_jump_round4/reference'
    rows,scores=arena.evaluate(trials[t],arena.read_params(ref/'p6-params.txt'),str(ref/'p6-controller'),trials[t]['task'],3)
    assert scores==main_before[t]['scores']
    write('p6_arena_replay.json',{'exact':True,'scores':scores,'rows':rows,'trial':trials[t]})
    print('P6 exact replay passed',flush=True)
    entries=[];records={};comparisons=[]
    for t in TRIALS:
        records[t]={}
        for r in registry:
            label=r['label'];artifact=OUT/f'arena_{t}_{label}.json'
            invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',t,'--params',r['params_file'],'--controller',r['controller'],'--note',f'gpt: landing-depth {label}; 664 matched pilot rollouts/family, inherited head frozen, predeclared choice, 64 fresh validations','--workers','3'],f'arena_{t}_{label}.log')
            d=read(artifact);records[t][label]=d
            local=arena.compare(d['trial'],before[t]['scores'],d['scores']);frontier=arena.compare(d['trial'],main_before[t]['scores'],d['scores']) if t in main_before else None
            valid=[score for score in d['scores'] if abs(score)<1e8]
            row={'trial':t,'label':label,'variant':r['variant'],'choice':r['choice'],'local':local,'main_frontier':frontier,'passes':len(valid),'n':len(d['scores']),'mean_valid':sum(valid)/len(valid) if valid else None,'mean_guard_coded':sum(d['scores'])/len(d['scores'])}
            entries.append(row);print(json.dumps(row),flush=True)
        for choice in ['recovery','distance']:
            pure='pure_'+choice;tcn='tcn_'+choice
            if pure in records[t] and tcn in records[t]:comparisons.append({'trial':t,'comparison':tcn+' minus '+pure,**arena.compare(trials[t],records[t][pure]['scores'],records[t][tcn]['scores'])})
        if 'tcn_distance' in records[t] and 'tcn_recovery' in records[t]:comparisons.append({'trial':t,'comparison':'tcn_distance minus tcn_recovery',**arena.compare(trials[t],records[t]['tcn_recovery']['scores'],records[t]['tcn_distance']['scores'])})
    write('arena_summary.json',{'entries':entries,'comparisons':comparisons});promotions=[]
    for t in TRIALS:
        eligible=[e for e in entries if e['trial']==t and e['local']['wins'] and (e['main_frontier'] is None or e['main_frontier']['wins'])]
        if not eligible:continue
        best=max(eligible,key=lambda e:e['mean_guard_coded']);r=next(r for r in registry if r['label']==best['label']);label=r['label'];artifact=OUT/f'promoted_{t}_{label}.json'
        invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',t,'--params',r['params_file'],'--controller',r['controller'],'--note',f'gpt: landing-depth {label}; beats local and recorded main frontier, matched pilot budgets and fresh validation','--workers','3','--promote'],f'promoted_{t}_{label}.log')
        c=read(ROOT/'playground/arena/champions.json')[t]
        assert c['result']=='promoted' and c['note'].startswith('gpt:')
        assert sha(ROOT/c['frozen_controller'])==r['controller_sha256'] and sha(ROOT/c['frozen_params'])==r['params_sha256']
        d=read(artifact);valid=[i for i,score in enumerate(d['scores']) if abs(score)<1e8];i=min(valid,key=lambda i:abs(d['scores'][i]-best['mean_valid']));seed=trials[t]['seeds'][i];stem=OUT/f'video_{t}_{label}'
        invoke(['playground/gpt_render.py',t,'--params',c['frozen_params'],'--controller',c['frozen_controller'],'--seed',str(seed),'--seconds','20','--out',str(stem)],f'video_{t}_{label}.log')
        promotions.append({**best,'champion':c,'seed':seed,'video':str(stem)+'.mp4','sheet':str(stem)+'_sheet.png'});write('promotions.json',promotions)
        print('Promoted and rendered',t,label,flush=True)
    if not promotions:write('promotions.json',[])
    if promotions:invoke(['playground/arena.py','recheck',*[r['trial'] for r in promotions],'--workers','3'],'recheck_promoted.log')
    write('champions_after.json',read(ROOT/'playground/arena/champions.json'))
    check_frozen()
if __name__=='__main__':main()
