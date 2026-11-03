"""Current requirement evidence without overwriting historical audit snapshots."""
import hashlib,json,subprocess
from pathlib import Path
import numpy as np
import arena
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'out/competitor_jump_round6'
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
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
    folders=[r1,*[ROOT/f'out/competitor_jump_round{i}' for i in [2,3,4]],ROOT/'out/competitor_jump_round5/support']
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
    manifests=[r1/'frozen_manifest.json',r1/'final_manifest.json',*[ROOT/f'out/competitor_jump_round{i}/manifest.json' for i in [2,3,4,5,6]],ROOT/'out/competitor_jump_round5/support/manifest.json']
    frozen=[p for f in manifests for p,h in read(f).items() if sha(ROOT/p)!=h];checks['frozen_sources_and_binaries_unchanged']=not frozen;details['frozen_drift']=frozen
    measured=read(r1/'bat_measured_motion.json');checks['batter_full_measured_motion_present']=len(measured)==5 and all(r['full_visible_interval'][1]>=7.79 and all('full_visible_longest_quiet_spans' in g and 'full_visible_mean_joint_travel_rad' in g for g in r['groups'].values()) for r in measured)
    checks['worktree_and_no_commits']=subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()=='codex/robolab-challengers' and subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()=='85e95c33680a0e04bb4245de3fe86e2ae3c3200a'
    checks['no_tracked_edits']=not subprocess.check_output(['git','diff','--name-only','HEAD'],cwd=ROOT,text=True).strip()
    report={'scope':'Evidence through round 5; this is not completion of the live round-6 refinement.','passed':all(checks.values()),'checks':checks,'details':details,'pending':['Complete the frozen round-6 training, fresh validation, arena comparison, audit and videos.','Inspect any new champion full-motion video and retain all failure modes.','Integrate final round-6 evidence into the report and results page.','Verify the current frontier before claiming a new main-arena win.']}
    (OUT/'requirements_preflight.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':checks,'pending':report['pending']},indent=2))
    assert report['passed']
if __name__=='__main__':main()
