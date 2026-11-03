"""Round 10: frozen outgoing-stroke candidates, current-frontier promotion gate."""
import json,subprocess,sys
from pathlib import Path
import arena
from gpt_dribble_outgoing import ROOT,OUT,VALID,BUDGET,read,write,sha,check_manifest
TRIALS=['dribble_crossover_25','dribble_crossover','dribble_arms_only']
MAIN=Path('/Users/erik/tungsten/bits/tungsten-robolab')
def check_frozen():
    check_manifest();reg=read(OUT/'candidates.json')
    assert {r['label'] for r in reg}=={'pure','tcn'}
    for r in reg:
        assert sha(r['params_file'])==r['params_sha256'] and sha(r['controller'])==r['controller_sha256']
        trained=read(OUT/f"{r['variant']}.json");assert trained['used']==BUDGET and trained['params']==r['params']
    for p,h in read(OUT/'judge_manifest.json').items():assert sha(ROOT/p)==h,p
    return reg

def invoke(args,log):
    with (OUT/log).open('w') as f:subprocess.run([sys.executable,*args],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True)

def main():
    assert not (OUT/'arena_summary.json').exists(),'Never duplicate a completed judging round'
    reg=check_frozen();before=read(OUT/'champions_before.json');main_before=read(OUT/'main_champions_before.json');trials=read(ROOT/'playground/arena/trials.json')
    assert (ROOT/'playground/arena/trials.json').read_bytes()==(OUT/'trials_before.json').read_bytes()
    local_now=read(ROOT/'playground/arena/champions.json');main_now=read(MAIN/'playground/arena/champions.json')
    main_trials=read(MAIN/'playground/arena/trials.json')
    for t in TRIALS:
        assert local_now[t]['scores']==before[t]['scores'],t
        assert trials[t]==main_trials[t],t
    write('main_champions_at_judging.json',main_now)
    main_before=main_now
    frontier_hashes={str(MAIN/c[k]):sha(MAIN/c[k]) for t,c in main_before.items() if t in TRIALS for k in ['frozen_controller','frozen_params']}
    write('main_frontier_manifest.json',frontier_hashes)
    validation=read(OUT/'validation.json')
    assert not any('error' in r['metrics'] for r in validation)
    assert len(validation)==len(VALID)*8
    for label in read(OUT/'protocol.json')['validation_groups']:assert {r['seed'] for r in validation if r['label']==label}==set(VALID)
    # Replay both boards against the exact unmodified task before entry.
    local_replays={}
    for t in TRIALS:
        c=before[t]
        rows,scores=arena.evaluate(trials[t],arena.read_params(ROOT/c['frozen_params']),str(ROOT/c['frozen_controller']),trials[t]['task'],3)
        assert scores==c['scores'],t
        local_replays[t]={'exact':True,'scores':scores,'rows':rows,'trial':trials[t]}
        print('Local exact replay',t,flush=True)
    write('local_replay.json',local_replays)
    # Replay current main incumbents; preserve the training-time snapshot too.
    replays={}
    for t in TRIALS:
        c=main_before[t]
        rows,scores=arena.evaluate(trials[t],arena.read_params(MAIN/c['frozen_params']),str(MAIN/c['frozen_controller']),trials[t]['task'],3)
        assert scores==c['scores'],t
        replays[t]={'exact':True,'scores':scores,'rows':rows,'trial':trials[t]}
        print('Main exact replay',t,flush=True)
    write('main_replay.json',replays)
    long=read(OUT/'endurance30.json')
    assert len(long)==32 and not any('error' in r['metrics'] for r in long)
    entries=[];records={};comparisons=[]
    for t in TRIALS:
        records[t]={}
        for r in reg:
            label=r['label'];artifact=OUT/f'arena_{t}_{label}.json';assert not artifact.exists()
            invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',t,'--params',r['params_file'],'--controller',r['controller'],'--note',f'gpt: outgoing crossover {label}; matched2048 rollouts/family, fixed inherited heads and catch feedback,64 untouched validations','--workers','3'],f'arena_{t}_{label}.log')
            d=read(artifact);records[t][label]=d;valid=[s for s in d['scores'] if abs(s)<1e8]
            row={'trial':t,'label':label,'variant':label,'local':arena.compare(trials[t],before[t]['scores'],d['scores']),'main_frontier':arena.compare(trials[t],main_before[t]['scores'],d['scores']),'passes':len(valid),'n':len(d['scores']),'mean_valid':sum(valid)/len(valid) if valid else None,'mean_guard_coded':sum(d['scores'])/len(d['scores'])}
            entries.append(row);print(json.dumps(row),flush=True)
        comparisons.append({'trial':t,'comparison':'tcn minus pure',**arena.compare(trials[t],records[t]['pure']['scores'],records[t]['tcn']['scores'])})
    write('arena_summary.json',{'entries':entries,'comparisons':comparisons});promotions=[]
    main_now=read(MAIN/'playground/arena/champions.json')
    assert all(main_now[t]['scores']==main_before[t]['scores'] for t in TRIALS),'Main frontier changed during judging; review before promotion'
    assert all(sha(p)==h for p,h in frontier_hashes.items())
    for t in TRIALS:
        eligible=[e for e in entries if e['trial']==t and e['local']['wins'] and e['main_frontier']['wins']]
        if not eligible:continue
        best=max(eligible,key=lambda e:e['mean_guard_coded']*(1 if trials[t].get('higher',True) else -1))
        r=next(r for r in reg if r['label']==best['label']);label=r['label'];artifact=OUT/f'promoted_{t}_{label}.json'
        invoke(['playground/gpt_arena_entry.py','--artifact',str(artifact),'eval',t,'--params',r['params_file'],'--controller',r['controller'],'--note',f'gpt: outgoing crossover {label}; beats local and main frontier, matched additional budgets, inherited parents and fresh validation','--workers','3','--promote'],f'promoted_{t}_{label}.log')
        c=read(ROOT/'playground/arena/champions.json')[t];d=read(artifact)
        assert c['result']=='promoted' and c['note'].startswith('gpt:')
        assert sha(ROOT/c['frozen_controller'])==r['controller_sha256'] and sha(ROOT/c['frozen_params'])==r['params_sha256']
        assert d['scores']==records[t][label]['scores']
        valid=[i for i,s in enumerate(d['scores']) if abs(s)<1e8];i=min(valid,key=lambda i:abs(d['scores'][i]-best['mean_valid']));seed=trials[t]['seeds'][i];stem=OUT/f'video_{t}_{label}'
        invoke(['playground/gpt_render.py',t,'--params',c['frozen_params'],'--controller',c['frozen_controller'],'--seed',str(seed),'--seconds','15','--out',str(stem)],f'video_{t}_{label}.log')
        promotions.append({**best,'champion':c,'seed':seed,'video':str(stem)+'.mp4','sheet':str(stem)+'_sheet.png'});write('promotions.json',promotions)
        print('Promoted and rendered',t,label,flush=True)
    if not promotions:write('promotions.json',[])
    if promotions:invoke(['playground/arena.py','recheck',*[r['trial'] for r in promotions],'--workers','3'],'recheck_promoted.log')
    write('champions_after.json',read(ROOT/'playground/arena/champions.json'));check_frozen()
if __name__=='__main__':main()
