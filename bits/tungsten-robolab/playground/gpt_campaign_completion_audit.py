"""Final requirement audit; preserve all historical snapshots."""
import hashlib,json,subprocess
from pathlib import Path
import numpy as np
import arena
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'out/gpt_campaign_final'
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    OUT.mkdir(exist_ok=True)
    r1=ROOT/'out/competitor_20260927';checks={};details={};summary=read(r1/'summary.json');protocol=read(r1/'protocol.json')
    checks['three_problems_two_families_each']=all({e['variant'] for e in summary['arena'] if e['problem']==p}=={'pure','tcn'} for p in ['jump','bat','dribble'])
    budgets={p:{v:read(r1/f'{p}_{v}.json')['used'] for v in ['pure','tcn']} for p in ['jump','bat','dribble']}
    checks['initial_budgets_matched']=all(all(n==protocol['budgets'][p] for n in values.values()) for p,values in budgets.items());details['budgets']=budgets
    checks['initial_search_archives_valid']=all(np.load(r1/f'{p}_{v}.npz')['X'].shape[1]==28 and np.isfinite(np.load(r1/f'{p}_{v}.npz')['F']).all() for p in budgets for v in ['pure','tcn'])
    checks['zero_initial_heads_exact_in_all_six_builds']=all(all(read(r1/f'{p}_{v}_parity.json')['parity'].values()) for p in budgets for v in ['pure','tcn'])
    integration=read(r1/'integration.json');checks['all_six_nonzero_heads_change_measured_motion']=len(integration)==6 and all(not r['errors'] and all(x>1e-8 for x in r['max_absolute_difference'].values()) for r in integration)
    checks['compiled_residual_spec_evidence']=(r1/'residual_spec.log').read_text().strip()=='50 checks passed: zero head, bounded output, temporal history, sample clock'
    fresh=[];time_order=[];durations=[]
    for p in budgets:
        for v in ['pure','tcn']:
            path=r1/f'{p}_{v}_validate.json';rows=read(path);candidate=[r for r in rows if r['kind']=='candidate']
            fresh.append(len(candidate)==24 and {r['seed'] for r in candidate}==set(protocol['validation_seeds']))
            fresh.append(not any('error' in r['metrics'] for r in rows))
            for e in summary['arena']:
                if e['problem']==p and e['variant']==v:time_order.append(path.stat().st_mtime<=Path(e['artifact']).stat().st_mtime)
            durations.extend(r['metrics']['time']>={'jump':6.,'bat':7.8,'dribble':15.}[p]-.01 for r in candidate)
    checks['fresh_validation_complete_and_error_free']=all(fresh);checks['validation_artifacts_precede_initial_arena']=all(time_order);checks['validation_measures_complete_rollouts']=all(durations)
    seeds=[set(protocol['training_seeds']),set(protocol['validation_seeds'])];trials=read(ROOT/'playground/arena/trials.json');arena_seeds={s for t in trials.values() for s in t['seeds']}
    checks['private_initial_seeds_disjoint']=not seeds[0]&seeds[1] and all(not s&arena_seeds for s in seeds)
    before=read(r1/'champions_before.json');comp=[]
    for e in summary['arena']:
        d=read(Path(e['artifact']));prior=before.get(e['trial'],{}).get('scores',[-1e9]*len(d['scores']));result=arena.compare(d['trial'],prior,d['scores'])
        comp.append(all(e[k]==result[k] for k in ['mean_diff','p','n','wins']))
    checks['initial_arena_decisions_recompute']=len(comp)==10 and all(comp)
    folders=[r1,*[ROOT/f'out/competitor_jump_round{i}' for i in [2,3,4]],ROOT/'out/competitor_jump_round5/support',*[ROOT/f'out/competitor_jump_round{i}' for i in [6,7]]]
    promotions=[p for folder in folders for p in read(folder/'promotions.json')]
    checks['promoted_frozen_copies_exact']=all(not (ROOT/p['champion']['frozen_controller']).is_symlink() and sha(ROOT/p['champion']['frozen_controller'])==sha(Path(p['champion']['controller'])) and sha(ROOT/p['champion']['frozen_params'])==sha(Path(p['champion']['params'])) for p in promotions)
    checks['promoted_names_and_notes']=all(Path(p['champion']['controller']).name.startswith('gpt-') and p['champion']['note'].startswith('gpt:') for p in promotions)
    checks['all_champion_videos_and_sheets_present']=all(Path(p['video']).is_file() and Path(p['sheet']).is_file() and Path(p['video']).with_suffix('.json').is_file() for p in promotions)
    details['champion_videos']=[p['video'] for p in promotions]
    wins={p:any(e['wins'] and e['problem']==p for e in summary['arena']) for p in budgets}
    wins['jump']=wins['jump'] or any(p['trial']=='search_jump_legal' for p in promotions)
    checks['three_selected_problems_have_recorded_arena_wins']=all(wins.values());details['recorded_problem_wins']=wins
    baseline=read(r1/'baseline_files.json');allowed={'playground/arena/trials.json','playground/arena/champions.json','playground/arena/history.jsonl'}
    drift=[p for p,h in baseline.items() if p not in allowed and sha(ROOT/p)!=h];checks['shared_sdk_and_inherited_files_unchanged']=not drift;details['inherited_drift']=drift
    old=dict(trials);old.pop('gpt_jump_stable6');checks['existing_trial_definitions_unchanged']=hashlib.sha256(json.dumps(old,indent=1).encode()).hexdigest()==baseline['playground/arena/trials.json']
    manifests=[r1/'frozen_manifest.json',r1/'final_manifest.json',*[ROOT/f'out/competitor_jump_round{i}/manifest.json' for i in [2,3,4,5,6,7]],ROOT/'out/competitor_jump_round5/support/manifest.json']
    frozen=[p for f in manifests for p,h in read(f).items() if sha(ROOT/p)!=h];checks['frozen_sources_and_binaries_unchanged']=not frozen;details['frozen_drift']=frozen
    measured=read(r1/'bat_measured_motion.json');checks['batter_full_measured_motion_present']=len(measured)==5 and all(r['full_visible_interval'][1]>=7.79 and all('full_visible_longest_quiet_spans' in g and 'full_visible_mean_joint_travel_rad' in g for g in r['groups'].values()) for r in measured)
    checks['worktree_and_no_commits']=subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()=='codex/robolab-challengers' and subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()=='85e95c33680a0e04bb4245de3fe86e2ae3c3200a'
    checks['no_tracked_edits']=not subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=ROOT,text=True).strip()
    # Recompute every recorded arena decision from the frozen per-seed rows.
    all_entries=[]; all_decisions=[]; all_validations=[]; candidates=set(); copies=[]; notes=[]
    history=[json.loads(line) for line in (ROOT/'playground/arena/history.jsonl').read_text().splitlines()]
    for round_id,folder in enumerate(folders,1):
        record=read(folder/('summary.json' if round_id==1 else 'arena_summary.json'))
        before_folder=folder.parent if round_id==5 else folder
        prior=read(before_folder/'champions_before.json')
        rows=record['arena' if round_id==1 else 'entries']
        for row in rows:
            variant=row['variant'];trial=row['trial'];label=row.get('label',variant)
            if round_id==1:
                artifact=Path(row['artifact']); validation=folder/f"{row['problem']}_{variant}_validate.json"
            elif round_id<=4:
                artifact=folder/f'arena_{variant}_{trial}.json';validation=folder/f'{variant}_validate.json'
            else:
                artifact=folder/f'arena_{trial}_{label}.json';validation=folder/'validation.json'
            d=read(artifact); result=arena.compare(d['trial'],prior.get(trial,{}).get('scores',[-1e9]*len(d['scores'])),d['scores'])
            stored=row.get('local',row)
            all_decisions.append(all(result[k]==stored[k] for k in ['mean_diff','p','n','wins']))
            if row.get('main_frontier'):
                main=read(before_folder/'main_champions_before.json')
                all_decisions.append(arena.compare(d['trial'],main[trial]['scores'],d['scores'])==row['main_frontier'])
            all_validations.append(validation.stat().st_mtime<=artifact.stat().st_mtime)
            controller=Path(d['controller']);controller=controller if controller.is_absolute() else ROOT/controller
            copies.append(controller.is_file() and not controller.is_symlink() and controller.parent==ROOT/'bin/challengers' and controller.name.startswith('gpt-'))
            candidates.add((round_id,str(controller),label))
            matching=[h for h in history if h['trial']==trial and h.get('controller')==str(controller) and 'vs_champion' in h]
            notes.append(bool(matching) and all(h['note'].startswith('gpt:') for h in matching))
            all_entries.append({'round':round_id,'trial':trial,'family':variant,'label':label,'artifact':str(artifact),'local':result,'main_frontier':row.get('main_frontier')})
    checks['all_52_arena_entries_recompute']=len(all_entries)==52 and all(all_decisions)
    checks['all_rounds_validate_before_arena']=all(all_validations)
    checks['all_20_selections_use_frozen_binary_copies']=len(candidates)==20 and all(copies)
    checks['all_challenger_arena_notes_prefixed']=all(notes)
    details['arena_entries']=len(all_entries);details['selected_challengers']=len(candidates);details['promotion_events']=len(promotions)
    audit_paths=[r1/'audit.json',folders[2]/'completion_audit.json',*[folder/'audit.json' for folder in folders[3:]]]
    checks['all_round_audits_pass']=all(read(p)['passed'] for p in audit_paths)
    details['round_audits']=[str(p) for p in audit_paths]
    # Full decode closes the earlier round-one first/last-frame-only media check.
    import imageio.v2 as imageio
    video_rows=[]
    for promotion in promotions:
        path=Path(promotion['video']); reader=imageio.get_reader(path);meta=reader.get_meta_data();count=0
        for frame in reader:
            assert frame.shape==(448,800,3),path
            count+=1
        reader.close();metrics=read(path.with_suffix('.json'))['metrics']
        video_rows.append({'file':str(path),'sha256':sha(path),'frames':count,'fps':meta['fps'],'seconds':count/meta['fps'],'simulation_seconds':metrics['time'],'fully_decoded':True})
    checks['every_promoted_video_fully_decoded']=len(video_rows)==len(promotions) and all(v['seconds']>=v['simulation_seconds']-.04 for v in video_rows)
    details['videos']=video_rows
    (OUT/'arena_ledger.json').write_text(json.dumps(all_entries,indent=2)+'\n')
    report={'scope':'Original three-problem request plus all seven completed research rounds. Arena wins are scoped to their recorded incumbents; later P6 and technique failures remain disclosed.','passed':all(checks.values()),'checks':checks,'details':details,'pending':[]}
    (OUT/'requirements_audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':checks,'counts':{k:details[k] for k in ['arena_entries','selected_challengers','promotion_events']}},indent=2))
    assert report['passed']
if __name__=='__main__':main()
