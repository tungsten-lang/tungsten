"""Read-only campaign checks, apart from writing this audit's evidence files."""
import hashlib,json,math,subprocess
from pathlib import Path
import imageio.v2 as imageio
import numpy as np
import arena
from gpt_jump_recover import legal
ROOT=Path(__file__).resolve().parent.parent
R1=ROOT/'out/competitor_20260927';R2=ROOT/'out/competitor_jump_round2';R3=ROOT/'out/competitor_jump_round3'
def read(p):return json.loads(p.read_text())
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    checks={};details={}
    baseline=read(R1/'baseline_files.json');allowed={'playground/arena/trials.json','playground/arena/champions.json','playground/arena/history.jsonl'}
    changed=[p for p,h in baseline.items() if p not in allowed and (not (ROOT/p).is_file() or digest(ROOT/p)!=h)]
    details['unexpected_inherited_changes']=changed;details['inherited_files_checked']=len(baseline);checks['shared_files_unchanged']=not changed
    drift=[]
    for folder,name in [(R1,'frozen_manifest.json'),(R1,'final_manifest.json'),(R2,'manifest.json'),(R3,'manifest.json')]:
        drift += [str(folder.relative_to(ROOT))+'/'+name+':'+p for p,h in read(folder/name).items() if digest(ROOT/p)!=h]
    details['frozen_drift']=drift;checks['frozen_source_binary_params_unchanged']=not drift
    trials=read(ROOT/'playground/arena/trials.json');old_trials=dict(trials);old_trials.pop('gpt_jump_stable6')
    checks['original_trials_byte_identical']=hashlib.sha256(json.dumps(old_trials,indent=1).encode()).hexdigest()==baseline['playground/arena/trials.json']
    checks['round2_and_round3_trials_byte_identical']=all((ROOT/'playground/arena/trials.json').read_bytes()==(folder/'trials_before.json').read_bytes() for folder in [R2,R3])
    checks['round1_complete_audit']=read(R1/'audit.json')['passed']
    budgets={};seedsets=[];p1=read(R1/'protocol.json')
    for key in ['training_seeds','validation_seeds']:seedsets.append((key,set(p1[key])))
    for p in ['jump','bat','dribble']:
        budgets[p]={v:read(R1/f'{p}_{v}.json')['used'] for v in ['pure','tcn']}
        checks[p+'_round1_budget']=all(n==p1['budgets'][p] for n in budgets[p].values())
    for folder in [R2,R3]:
        protocol=read(folder/'protocol.json');budgets[folder.name]={v:read(folder/f'{v}.json')['used'] for v in ['pure','tcn']}
        checks[folder.name+'_budget']=all(n==protocol['budget_each'] for n in budgets[folder.name].values())
        for key in ['training','validation']:seedsets.append((folder.name+'_'+key,set(protocol[key])))
        for v in ['pure','tcn']:
            rows=read(folder/f'{v}_validate.json');checks[folder.name+'_'+v+'_fresh_complete']={r['seed'] for r in rows if r['kind']=='candidate'}==set(protocol['validation'])
    reference=read(R3/'original_pinned_provenance.json');original=read(R1/'champions_before.json')['search_jump_legal']
    checks['corrected_original_reference_is_pinned']=all(reference[k]==original[k] for k in ['frozen_controller','frozen_params']) and all(digest(ROOT/p)==h for p,h in reference['sha256'].items())
    corrected=read(R3/'original_pinned_validate.json')
    checks['corrected_original_complete_and_zero_residual']={r['seed'] for r in corrected}==set(read(R3/'protocol.json')['validation']) and all(all(x==0. for x in r['metrics']['residual_peak_rad']) for r in corrected)
    details['original_reference_correction']=reference
    details['budgets']=budgets
    arena_seeds=set(s for t in trials.values() for s in t['seeds'])
    details['seed_intersections']=[(a,b,sorted(sa&sb)) for i,(a,sa) in enumerate(seedsets) for b,sb in seedsets[i+1:] if sa&sb]
    checks['training_validation_disjoint']=not details['seed_intersections'] and all(not ss&arena_seeds for _,ss in seedsets)
    checks['round2_full_search_archives_valid']=all(np.load(R2/f'{v}.npz')['X'].shape==(256,32) and np.isfinite(np.load(R2/f'{v}.npz')['F']).all() and bool((np.load(R2/f'{v}.npz')['F']>-1e6).all()) for v in ['pure','tcn'])
    errors=[];nonfinite=[]
    def scan(obj,path):
        if isinstance(obj,dict):
            if 'error' in obj:errors.append((path,obj['error']))
            for k,v in obj.items():scan(v,path+'.'+k)
        elif isinstance(obj,list):
            for i,v in enumerate(obj):scan(v,path+f'[{i}]')
        elif isinstance(obj,float) and not math.isfinite(obj):nonfinite.append(path)
    for folder in [R2,R3]:
        paths=[folder/'pure.json',folder/'tcn.json',*folder.glob('*_validate.json'),folder/'endurance20.json',*folder.glob('arena_*.json')]
        for p in paths:scan(read(p),str(p.relative_to(ROOT)))
    details['simulation_errors']=errors;details['nonfinite_values']=nonfinite;checks['new_runs_no_errors_or_nonfinite']=not errors and not nonfinite
    a=np.load(R2/'pure_start_validation.npz');b=np.load(R2/'tcn_start_validation.npz')
    details['round2_zero_head_parity']={k:bool(np.array_equal(a[k],b[k])) for k in ['command','measured','activation','q']}
    checks['round2_zero_head_exact_parity']=all(details['round2_zero_head_parity'].values())
    details['temporal_full_vs_zero_trace_effect']={}
    for folder in [R2,R3]:
        a=np.load(folder/'tcn_candidate_validation.npz');b=np.load(folder/'tcn_zero_head_validation.npz')
        delta={k:float(np.max(np.abs(a[k]-b[k]))) for k in ['command','measured','activation','q']}
        details['temporal_full_vs_zero_trace_effect'][folder.name]=delta
        checks[folder.name+'_residual_changes_measured_motion']=all(x>1e-8 for x in delta.values())
    recompute=[]
    for folder in [R2,R3]:
        before=read(folder/'champions_before.json');verdicts=read(folder/'arena_summary.json')['entries']
        for row in verdicts:
            d=read(folder/f"arena_{row['variant']}_{row['trial']}.json");c=arena.compare(d['trial'],before[row['trial']]['scores'],d['scores'])
            recompute.append(all(row[k]==c[k] for k in ['mean_diff','p','n','wins']))
    checks['all_twelve_new_arena_verdicts_recomputed']=len(recompute)==12 and all(recompute)
    champs=read(ROOT/'playground/arena/champions.json');promotions=[r for folder in [R1,R2,R3] for r in read(folder/'promotions.json')]
    checks['all_promoted_frozen_files_match'] = all(digest(ROOT/r['champion']['frozen_controller'])==digest(Path(r['champion']['controller'])) and digest(ROOT/r['champion']['frozen_params'])==digest(Path(r['champion']['params'])) for r in promotions)
    checks['promotion_notes_have_gpt_prefix']=all(r['champion']['note'].startswith('gpt:') for r in promotions)
    own_trials=['search_jump_legal','search_jump_robust_legal','gpt_jump_stable6','bat_power','dribble_crossover_25']
    checks['five_current_worktree_champions_are_gpt']=all(champs[t]['note'].startswith('gpt:') for t in own_trials)
    details['current_champions']={t:{'mean_valid':float(np.mean([s for s in champs[t]['scores'] if abs(s)<1e8])),'passes':sum(abs(s)<1e8 for s in champs[t]['scores']),'n':len(champs[t]['scores']),'controller':champs[t]['frozen_controller'],'params':champs[t]['frozen_params']} for t in own_trials}
    recheck=(R3/'recheck_final.log').read_text();details['recheck_log']=recheck
    checks['three_jump_champions_replay_exactly']=all(any(line.startswith(t+':') and line.endswith('  OK') for line in recheck.splitlines()) for t in own_trials[:3]) and 'DRIFT' not in recheck
    oldrecheck=(R1/'recheck_promoted.log').read_text();checks['bat_and_dribble_replayed']=all(any(line.startswith(t+':') and line.endswith('  OK') for line in oldrecheck.splitlines()) for t in own_trials[3:])
    videos=[]
    for folder in [R2,R3]:
        for p in sorted(folder.glob('video_*.mp4')):
            reader=imageio.get_reader(p);meta=reader.get_meta_data();n=0
            for frame in reader:
                assert frame.shape==(448,800,3),(p,frame.shape)
                n+=1
            reader.close();sim=read(p.with_suffix('.json'))['metrics']['time'];duration=n/meta['fps']
            assert duration>=sim-.04,(p,duration,sim)
            videos.append({'file':str(p),'fully_decoded_frames':n,'fps':meta['fps'],'duration_s':duration,'simulation_s':sim})
    details['videos']=videos;checks['all_new_champion_videos_decoded']=len(videos)==sum(len(read(folder/'promotions.json')) for folder in [R2,R3])
    (R3/'video_audit.json').write_text(json.dumps(videos,indent=2)+'\n')
    details['branch']=subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip();details['head']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    checks['no_commits']=details['branch']=='codex/robolab-challengers' and details['head'].startswith('85e95c336')
    checks['no_tracked_edits']=not subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=ROOT,text=True).strip()
    report={'passed':all(checks.values()),'checks':checks,'details':details}
    (R3/'completion_audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':checks,'current_champions':details['current_champions']},indent=2))
    assert report['passed']
if __name__=='__main__':main()
